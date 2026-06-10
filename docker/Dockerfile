FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY server/ ./server/
WORKDIR /app/server
RUN go build -o /aceso-server ./cmd/server

FROM alpine:3.20
COPY --from=builder /aceso-server /usr/local/bin/aceso-server
EXPOSE 8080
ENTRYPOINT ["aceso-server"]
