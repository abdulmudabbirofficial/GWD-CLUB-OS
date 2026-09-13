'use strict';

/**
 * Wipe the database back to nothing.
 *
 * Months of smoke-test runs leave a database full of "Test Dept mtzlxee1" and
 * forty throwaway members, which makes every picker in the app unusable. This
 * drops all of it so the next `npm start` reseeds clean: the six real
 * departments, a pending Lead account for each, and the pre-seeded roots of
 * trust from .env.
 *
 * Destructive and deliberately awkward:
 *
 *   node scripts/reset.js --yes
 *
 * Uploaded files go too, since the documents and receipts pointing at them are
 * about to disappear and orphaned bytes on disk help nobody.
 */

const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');

const config = require('../src/config');
const db = require('../src/db');

async function main() {
  const confirmed = process.argv.includes('--yes');

  console.log('');
  console.log('  This deletes EVERY account, department, task, event and file');
  console.log(`  in "${config.mongoDb}" at ${config.mongoUri.replace(/\/\/[^@]*@/, '//')}`);
  console.log('');

  if (!confirmed) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answer = await new Promise((resolve) => {
      rl.question('  Type the database name to confirm: ', resolve);
    });
    rl.close();
    if (answer.trim() !== config.mongoDb) {
      console.log('\n  Not confirmed. Nothing was deleted.\n');
      process.exit(1);
    }
  }

  await db.connect();
  const database = db.database();

  const collections = await database.listCollections().toArray();
  let dropped = 0;
  for (const { name } of collections) {
    if (name.startsWith('system.')) continue;
    await database.collection(name).deleteMany({});
    dropped += 1;
  }

  // Uploaded documents and receipts. The rows that referenced them are gone, so
  // leaving the bytes behind would just be litter nobody can trace.
  let files = 0;
  if (fs.existsSync(config.uploadDir)) {
    for (const entry of fs.readdirSync(config.uploadDir)) {
      const target = path.join(config.uploadDir, entry);
      if (fs.statSync(target).isFile()) {
        fs.unlinkSync(target);
        files += 1;
      }
    }
  }

  console.log('');
  console.log(`  Emptied ${dropped} collections and removed ${files} uploaded files.`);
  console.log('  Start the server to reseed:  npm start');
  console.log('');

  await db.close();
  process.exit(0);
}

main().catch((error) => {
  console.error('\n  Reset failed:', error.message, '\n');
  process.exit(1);
});
