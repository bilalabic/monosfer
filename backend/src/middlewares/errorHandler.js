export function errorHandler(error, _request, response, _next) {
  const statusCode = Number(error.statusCode) || 500;
  const message = statusCode === 404 ? "Route not found" : "Internal server error";

  response.status(statusCode).json({
    error: {
      message,
      statusCode,
    },
  });
}
