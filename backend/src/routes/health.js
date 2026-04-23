import { Router } from "express";
import { getHealthStatus } from "../controllers/healthController.js";
import { validateHealthRequest } from "../validators/healthValidator.js";

const healthRouter = Router();

healthRouter.get("/", validateHealthRequest, getHealthStatus);

export default healthRouter;
