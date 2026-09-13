import {requestLauncherStop} from '../services/api/launcher-control.mjs';
try {
  const result=await requestLauncherStop();
  console.log(result.running?'Owned Mate services stopped. Pending executions remain recoverable.':'No Mate launcher owns services in this checkout.');
} catch(error){console.error(error.message);process.exitCode=1;}
