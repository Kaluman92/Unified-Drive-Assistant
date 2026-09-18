// api/fault-guidance.js
//
// ============================================================
// BACKEND — MULTI-PROVIDER AI PROXY (Vercel serverless function)
// ------------------------------------------------------------
// No Firebase. A single Vercel serverless function that holds
// all three providers' API keys server-side and proxies a fault
// to whichever one the app requests, normalizing each provider's
// very different request/response shape into one plain
// { guidance: "..." } response the app understands.
//
// Deployed at: https://<your-project>.vercel.app/api/fault-guidance
//
// REQUIRED ENVIRONMENT VARIABLES (set in the Vercel dashboard —
// Project -> Settings -> Environment Variables — never commit
// these to git):
//   ANTHROPIC_API_KEY   (from console.anthropic.com)
//   OPENAI_API_KEY      (from platform.openai.com)
//   GEMINI_API_KEY      (from aistudio.google.com)
//
// OPTIONAL — override the exact model used per provider without
// touching code (model names change over time; verify the current
// recommended one in each provider's docs before deploying):
//   ANTHROPIC_MODEL   (default: claude-sonnet-5)
//   OPENAI_MODEL      (default: gpt-4o-mini)
//   GEMINI_MODEL      (default: gemini-2.0-flash)
//
// REQUEST BODY (sent by AIAssistantService.swift):
//   {
//     "provider": "claude" | "chatgpt" | "gemini",
//     "brand": "Siemens", "family": "S120", "code": "F30027",
//     "title": "...", "cause": "...", "remedy": "..."
//   }
//
// RESPONSE: { "guidance": "..." }  or  { "error": "..." } with a
// non-200 status.
// ============================================================

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Use POST' });
    return;
  }

  const { provider, brand, family, code, title, cause, remedy } = req.body || {};

  if (!provider || !code) {
    res.status(400).json({ error: 'Missing required fields (provider, code)' });
    return;
  }

  const prompt = buildPrompt({ brand, family, code, title, cause, remedy });

  try {
    let guidance;
    switch (provider) {
      case 'claude':
        guidance = await callClaude(prompt);
        break;
      case 'chatgpt':
        guidance = await callChatGPT(prompt);
        break;
      case 'gemini':
        guidance = await callGemini(prompt);
        break;
      default:
        res.status(400).json({ error: `Unknown provider "${provider}"` });
        return;
    }
    res.status(200).json({ guidance });
  } catch (err) {
    console.error(`[fault-guidance] ${provider} error:`, err);
    res.status(502).json({ error: `Upstream ${provider} request failed: ${err.message}` });
  }
}

function buildPrompt({ brand, family, code, title, cause, remedy }) {
  return `You are helping a field engineer troubleshoot a variable-frequency drive fault. Give a short, practical, step-by-step checklist a technician could follow on-site. Do not invent facts about the specific drive beyond what's given below — if you're not sure, say so.

Brand: ${brand || 'unknown'}
Drive family: ${family || 'unknown'}
Fault code: ${code}
Fault name: ${title || ''}
Known cause: ${cause || ''}
Known remedy: ${remedy || ''}

Expand this into clear, numbered troubleshooting steps a technician can follow in the field. Keep it under 150 words.`;
}

// MARK: - Anthropic (Claude)

async function callClaude(prompt) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not configured on the server');

  const model = process.env.ANTHROPIC_MODEL || 'claude-sonnet-5';

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: 500,
      messages: [{ role: 'user', content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Claude API returned ${response.status}: ${await response.text()}`);
  }

  const data = await response.json();
  const textBlock = (data.content || []).find((block) => block.type === 'text');
  return textBlock?.text || 'No guidance returned.';
}

// MARK: - OpenAI (ChatGPT)

async function callChatGPT(prompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY not configured on the server');

  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      max_tokens: 500,
      messages: [{ role: 'user', content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI API returned ${response.status}: ${await response.text()}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || 'No guidance returned.';
}

// MARK: - Google (Gemini)

async function callGemini(prompt) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY not configured on the server');

  const model = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 500 },
    }),
  });

  if (!response.ok) {
    throw new Error(`Gemini API returned ${response.status}: ${await response.text()}`);
  }

  const data = await response.json();
  return data.candidates?.[0]?.content?.parts?.[0]?.text || 'No guidance returned.';
}
