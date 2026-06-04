FROM node:20-slim

# Install system dependencies for Puppeteer and ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 7860

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install

COPY . .

ENV PORT=7860
ENV HEADLESS=true

CMD ["npm", "start"]