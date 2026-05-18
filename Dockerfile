FROM node:20-bookworm-slim

WORKDIR /app
COPY . .

CMD ["node", "scripts/run_experiments.js"]
