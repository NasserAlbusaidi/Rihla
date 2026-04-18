import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

// Callable exports are wired in subsequent waves:
// export { getSignedUploadUrl } from './callables/getSignedUploadUrl';
// export { listDocumentsWithUrls } from './callables/listDocumentsWithUrls';
// export { listMemoriesWithUrls } from './callables/listMemoriesWithUrls';
// export { deleteStorageObject } from './callables/deleteStorageObject';
