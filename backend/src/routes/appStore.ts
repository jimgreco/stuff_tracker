import { Router, Request, Response } from 'express';
import { applyAppStoreNotification } from '../lib/appStore';

const router = Router();

router.post('/notifications', async (req: Request, res: Response) => {
  const signedPayload = typeof req.body?.signedPayload === 'string'
    ? req.body.signedPayload
    : typeof req.body?.signed_payload === 'string'
      ? req.body.signed_payload
      : undefined;

  if (!signedPayload) {
    res.status(400).json({ error: 'signedPayload required' });
    return;
  }

  const result = await applyAppStoreNotification(signedPayload);
  res.json(result);
});

export default router;
