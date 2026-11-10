FROM node:22.22.0-bookworm-slim@sha256:7cc56ef285a8568121537d17b05e72128f01b89c54607b51acf084a50ef483f3
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=secret,id=proxy_ca,required=true NODE_EXTRA_CA_CERTS=/run/secrets/proxy_ca npm ci  --strict-ssl=true
COPY --chown=node:node index.html vite.config.js .oxlintrc.json ./
COPY --chown=node:node src ./src
COPY --chown=node:node public ./public
RUN printf "node_modules/\ndist/\n" > .gitignore && chown -R node:node /app
USER node
CMD ["npm", "run", "dev", "--", "--config", "/opt/codex-dev/vite.config.mjs", "--configLoader", "native"]
