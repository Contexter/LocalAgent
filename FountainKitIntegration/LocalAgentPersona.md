---
title: LocalAgentPersona
version: 1
description: >
  Persona that routes chat requests requiring on-device function-calling to a
  local HTTP service compatible with OpenAI's function-calling schema.

agent:
  kind: http
  base_url: http://127.0.0.1:8080
  endpoint: /chat
  protocol: openai-chat
  supports:
    - function_calling
    - text_completion

routing:
  mode: local
  hints:
    - offline
    - privacy
    - function-tools

notes: |
  This persona expects the local AgentService to be running. Requests sent to
  the gateway will be forwarded here when the planner determines that a local
  function-calling LLM is appropriate. The /chat endpoint accepts `messages`
  and a `functions` array and returns either a structured `function_call` or
  a normal assistant message.
---

# LocalAgentPersona

Use this persona when you need offline function-calling on Apple devices.
It assumes AgentService is running at http://127.0.0.1:8080.

