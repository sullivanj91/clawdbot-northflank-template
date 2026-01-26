# Clawdbot Northflank Template (1‑click deploy)

> Adapted from [@vignesh07's template](https://github.com/vignesh07/clawdbot-railway-template) for use with Northflank.


This repo packages **Clawdbot** for Northflank with a small **/setup** web wizard so users can deploy and onboard **without running any commands**.

## What you get

- **Clawdbot Gateway + Control UI** (served at `/` and `/clawdbot`)
- A friendly **Setup Wizard** at `/setup` (protected by a password)
- Persistent state via **Northflank Volume** (so config/credentials/memory survive redeploys)

## How it works (high level)

- The container runs a wrapper web server.
- The wrapper protects `/setup` with `SETUP_PASSWORD`.
- During setup, the wrapper runs `clawdbot onboard --non-interactive ...` inside the container, writes state to the volume, and then starts the gateway.
- After setup, **`/` is Clawdbot**. The wrapper reverse-proxies all traffic (including WebSockets) to the local gateway process.

## Northflank deploy instructions

1. Create an [account on Northflank](https://app.northflank.com/signup)
2. Click [Deploy Clawdbot now](https://northflank.com/stacks/deploy-docuseal)
3. Click Deploy stack to build and run the Clawdbot template
4. Wait for the deployment to complete
5. Open the public Clawdbot URL

Then:
- Visit `https://p01--<your-app>--xxxx.code.run/setup`
- Complete setup
- Visit `https://p01--<your-app>--xxxx.code.run/` and `/clawdbot`

## Getting chat tokens (so you don’t have to scramble)

### Telegram bot token
1) Open Telegram and message **@BotFather**
2) Run `/newbot` and follow the prompts
3) BotFather will give you a token that looks like: `123456789:AA...`
4) Paste that token into `/setup`

### Discord bot token
1) Go to the Discord Developer Portal: https://discord.com/developers/applications
2) **New Application** → pick a name
3) Open the **Bot** tab → **Add Bot**
4) Copy the **Bot Token** and paste it into `/setup`
5) Invite the bot to your server (OAuth2 URL Generator → scopes: `bot`, `applications.commands`; then choose permissions)

## Local smoke test

```bash
docker build -t clawdbot-northflank-template .

docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e SETUP_PASSWORD=test \
  -e CLAWDBOT_STATE_DIR=/data/.clawdbot \
  -e CLAWDBOT_WORKSPACE_DIR=/data/workspace \
  -v $(pwd)/.tmpdata:/data \
  clawdbot-northflank-template

# open http://localhost:8080/setup (password: test)
```
