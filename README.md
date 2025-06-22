# ThreadAgent

Rails app that processes Slack threads and creates Notion pages via webhooks.

## Setup

1. **Environment Variables**
   ```bash
   THREAD_AGENT_SLACK_BOT_TOKEN=xoxb-your-bot-token
   THREAD_AGENT_SLACK_SIGNING_SECRET=your-signing-secret
   THREAD_AGENT_NOTION_TOKEN=secret_your-notion-token
   ```

2. **Slack Webhook URL**
   ```
   POST https://your-app.com/thread_agent/webhooks/slack
   ```

3. **Test the webhook** (with proper signature):
   ```bash
   # Note: Real signatures require timestamp + HMAC-SHA256
   curl -X POST https://your-app.com/thread_agent/webhooks/slack \
     -H "Content-Type: application/json" \
     -H "X-Slack-Request-Timestamp: $(date +%s)" \
     -H "X-Slack-Signature: v0=your-hmac-signature" \
     -d '{"type":"url_verification","challenge":"test"}'
   ```

## License

This project is licensed under the **Business Source License 1.1 (BSL 1.1)**.

- ✅ You may use, modify, and self-host the code internally — including in production.
- ❌ You may not offer the code or a derivative as a commercial or hosted service.
- 🕒 The license automatically converts to [MIT](https://opensource.org/licenses/MIT) **three years after each version's release**.

See [LICENSE](./LICENSE) for full terms.
