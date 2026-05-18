import dotenv from 'dotenv';
dotenv.config();

import { createApp } from './app';
import { validateRuntimeEnvironment } from './lib/env';

validateRuntimeEnvironment();
const PORT = Number(process.env.PORT ?? 3002);
const app = createApp();

app.listen(PORT, () => console.log(`stuff-tracker API listening on :${PORT}`));
