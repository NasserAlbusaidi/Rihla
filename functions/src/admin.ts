import { getApps, initializeApp } from 'firebase-admin/app';

if (!getApps().length) {
  const projectId =
    process.env.GCLOUD_PROJECT
    ?? process.env.GOOGLE_CLOUD_PROJECT
    ?? process.env.PROJECT_ID;
  const storageBucket =
    process.env.FIREBASE_STORAGE_BUCKET
    ?? (projectId ? `${projectId}.firebasestorage.app` : undefined);

  initializeApp(storageBucket ? { storageBucket } : undefined);
}
