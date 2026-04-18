import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { getSignedUploadUrl } from './callables/getSignedUploadUrl';
export { listDocumentsWithUrls } from './callables/listDocumentsWithUrls';
export { listMemoriesWithUrls } from './callables/listMemoriesWithUrls';
// Wave 2 continued:
// export { deleteStorageObject } from './callables/deleteStorageObject';
