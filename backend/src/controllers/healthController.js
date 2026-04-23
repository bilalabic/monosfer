import { buildHealthResponse } from "../services/healthService.js";

export function getHealthStatus(_request, response) {
  response.status(200).json(buildHealthResponse());
}
