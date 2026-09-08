FROM node:18-alpine

WORKDIR /app

RUN apk add --no-cache curl

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -f http://localhost:3000/ready || exit 1

CMD ["npm", "start"]

