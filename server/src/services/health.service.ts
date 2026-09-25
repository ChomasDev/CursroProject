const startedAt = Date.now();

export type HealthStatus = {
  status: "ok";
  uptimeSeconds: number;
};

export function getHealth(): HealthStatus {
  return {
    status: "ok",
    uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
  };
}
