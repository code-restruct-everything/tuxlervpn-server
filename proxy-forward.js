const net = require("net");

const listenHost = process.env.TUXLER_FORWARD_LISTEN_HOST || "0.0.0.0";
const listenPort = parsePort(
  process.env.TUXLER_FORWARD_LISTEN_PORT,
  10080,
  "TUXLER_FORWARD_LISTEN_PORT"
);
const targetHost = process.env.TUXLER_FORWARD_TARGET_HOST || "127.0.0.1";
const targetPort = parsePort(
  process.env.TUXLER_FORWARD_TARGET_PORT,
  23321,
  "TUXLER_FORWARD_TARGET_PORT"
);

function parsePort(value, fallback, name) {
  const port = value ? Number(value) : fallback;

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error(`[proxy-forward] invalid ${name}: ${value}`);
    process.exit(1);
  }

  return port;
}

function closeBoth(clientSocket, targetSocket) {
  clientSocket.destroy();
  targetSocket.destroy();
}

const server = net.createServer((clientSocket) => {
  const targetSocket = net.connect({
    host: targetHost,
    port: targetPort,
  });

  targetSocket.on("connect", () => {
    clientSocket.pipe(targetSocket);
    targetSocket.pipe(clientSocket);
  });

  clientSocket.on("error", () => closeBoth(clientSocket, targetSocket));
  targetSocket.on("error", () => closeBoth(clientSocket, targetSocket));
  clientSocket.on("close", () => targetSocket.destroy());
  targetSocket.on("close", () => clientSocket.destroy());
});

server.on("error", (err) => {
  console.error(`[proxy-forward] listen failed: ${err.message}`);
  process.exit(1);
});

server.listen(listenPort, listenHost, () => {
  console.log(
    `[proxy-forward] listening ${listenHost}:${listenPort} -> ${targetHost}:${targetPort}`
  );
});
