FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install --no-audit --no-fund
COPY . .
ENV REACT_APP_USER_SERVICE_URL=/user
ENV REACT_APP_PRODUCT_SERVICE_URL=/product
ENV REACT_APP_CART_SERVICE_URL=/cart
ENV REACT_APP_ORDER_SERVICE_URL=/order
RUN npm run build
FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
