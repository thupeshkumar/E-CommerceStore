FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY --chown=node:node . .
USER node
EXPOSE 3001
CMD ["node", "server.js"]
