'use strict';

/** One pool thread. Does nothing but bcrypt, so the main loop never has to. */

const bcrypt = require('bcryptjs');
const { parentPort } = require('node:worker_threads');

parentPort.on('message', async ({ id, op, args }) => {
  try {
    const value = op === 'hash'
      ? await bcrypt.hash(args[0], args[1])
      : await bcrypt.compare(args[0], args[1]);
    parentPort.postMessage({ id, value });
  } catch (error) {
    parentPort.postMessage({ id, error: error.message });
  }
});
