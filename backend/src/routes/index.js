import { Router } from "express";
import healthRouter from "./health.js";
import authRouter from "./auth.js";
import deliveriesRouter from "./deliveries.js";

const apiRouter = Router();

apiRouter.use("/health", healthRouter);
apiRouter.use("/auth", authRouter);
apiRouter.use("/deliveries", deliveriesRouter);

export default apiRouter;
