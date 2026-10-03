import { IncomingMessage, ServerResponse } from 'node:http';
import { Duplex } from 'node:stream';
import type { Express } from 'express';

// Exercise the real Express middleware/router stack without opening a socket.
export async function request(app: Express, url: string, options: {
  method?: string;
  headers?: Record<string, string>;
  body?: object;
} = {}) {
  const chunks: Buffer[] = [];
  const socket = new Duplex({
    read() {},
    write(chunk, _encoding, callback) { chunks.push(Buffer.from(chunk)); callback(); },
  });
  const req = new IncomingMessage(socket as never);
  req.method = options.method ?? 'GET';
  req.url = url;
  req.headers = { host: 'localhost', ...Object.fromEntries(
    Object.entries(options.headers ?? {}).map(([name, value]) => [name.toLowerCase(), value])
  ) };
  const body = options.body === undefined ? undefined : Buffer.from(JSON.stringify(options.body));
  if (body) {
    req.headers['content-type'] = 'application/json';
    req.headers['content-length'] = String(body.length);
  }
  const res = new ServerResponse(req);
  res.assignSocket(socket as never);
  const finished = new Promise<void>((resolve, reject) => {
    res.on('finish', resolve);
    res.on('error', reject);
  });
  app(req, res);
  req.complete = true;
  req.push(body ?? null);
  if (body) req.push(null);
  await finished;
  const raw = Buffer.concat(chunks).toString('utf8');
  socket.destroy();
  return { status: res.statusCode, headers: res.getHeaders(), text: raw.slice(raw.indexOf('\r\n\r\n') + 4) };
}
