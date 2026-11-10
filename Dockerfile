# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# zen-proxy — containerized OpenAI/Anthropic-compatible proxy for OpenCode Zen
# free models.
#
# WHY BUN, NOT NODE
# -----------------
# OpenCode's free-tier gate fingerprints the fetch stack: it 429s Node's stack
# (even with byte-identical headers, cookies and bodies) and only accepts the
# Bun stack. So anonymous access ("Bearer public") — the whole point of this
# project — requires Bun. Node works only when you bring a Zen API key (BYOK)
# and the proxy warns at boot. This image therefore runs on Bun.
#
# HOW THE PROXY FINDS ITS FILES
# -----------------------------
# zen-proxy.mjs resolves every local input relative to its own directory
# (__dirname), and writes its config (zen-proxy.json) there on first boot:
#   models.json, agent-tools.json, agent-preamble.txt   (runtime inputs)
#   public/index.html                                   (dashboard at /)
#   zen-proxy.json                                      (config, generated)
# So all of them live together in one writable /app directory.
# ---------------------------------------------------------------------------
FROM bun:1.2

WORKDIR /app

# Zero-dependency runtime inputs. models.json ships a baked fallback catalog,
# but the real one is copied in here so the current catalog is served.
COPY zen-proxy.mjs models.json agent-tools.json agent-preamble.txt ./
COPY public/ ./public/

# Listen on all interfaces so Docker's -p port mapping can reach it
# (the proxy's built-in default is 127.0.0.1, which only works inside here).
# Every other setting is tunable via env — see the repo README "Configuration".
ENV HOST=0.0.0.0 \
    PORT=8787

# zen-proxy.json is created on first boot; the official image runs as the
# non-root `bun` user, so make /app writable for it.
RUN chown -R bun:bun /app

USER bun

EXPOSE 8787

# /health reports the last-known catalog state without calling upstream, so
# this is a cheap, honest liveness probe. It uses bun's built-in fetch
# (curl is not present in the runtime image) and avoids shell metacharacters
# ($ / backticks) so Docker's sh -c wrapper cannot mangle it.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=5 \
  CMD bun -e "(async()=>{try{const r=await fetch('http://127.0.0.1:'+process.env['PORT']+'/health');process.exit(r.ok?0:1)}catch{process.exit(1)}})()"

CMD ["bun", "zen-proxy.mjs"]
