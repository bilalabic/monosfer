import { Router } from "express";
import healthRouter from "./health.js";
import authRouter from "./auth.js";
import deliveriesRouter from "./deliveries.js";
import couriersRouter from "./couriers.js";

const apiRouter = Router();

apiRouter.use("/health", healthRouter);
apiRouter.use("/auth", authRouter);
apiRouter.use("/deliveries", deliveriesRouter);
apiRouter.use("/couriers", couriersRouter);

export default apiRouter;
