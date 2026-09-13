import {checkDeviceConnection} from '../services/api/device-connection.mjs';
try {
  const result=await checkDeviceConnection(process.env);
  console.log(`HTTPS API verified from this Mac: ${result.apiURL}. Complete pairing on the iPhone to verify phone access.`);
} catch(error){console.error(error.message);process.exitCode=1;}
