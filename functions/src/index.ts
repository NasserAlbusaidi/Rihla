import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { getSignedUploadUrl } from './callables/getSignedUploadUrl';
// Remaining callables in Wave 2:
// export { listDocumentsWithUrls } from './callables/listDocumentsWithUrls';
// export { listMemoriesWithUrls } from './callables/listMemoriesWithUrls';
// export { deleteStorageObject } from './callables/deleteStorageObject';
