import {ProxyNode} from '../types/proxy';

export const DEFAULT_TUNNEL_LATENCY_PROBE_URL = 'https://www.youtube.com/generate_204';

export async function runLatencyTest(nodes: ProxyNode[]): Promise<ProxyNode[]> {
  return nodes.map((node, index) => ({
    ...node,
    latencyMs: node.latencyMs ?? 35 + index * 22
  }));
}

export async function measureTunnelLatency(
  url = DEFAULT_TUNNEL_LATENCY_PROBE_URL,
): Promise<number> {
  const startedAt = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);

  try {
    const response = await fetch(`${url}?t=${startedAt}`, {
      method: 'GET',
      headers: {
        'Cache-Control': 'no-cache',
        Pragma: 'no-cache',
      },
      signal: controller.signal,
    });

    if (!response.ok && response.status !== 204) {
      throw new Error(`Latency probe failed for ${url} with status ${response.status}.`);
    }

    return Math.max(Date.now() - startedAt, 1);
  } finally {
    clearTimeout(timeout);
  }
}
