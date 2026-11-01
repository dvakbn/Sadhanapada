import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const url = (process.env.SUPABASE_URL || '').trim();
const anonKey = (process.env.SUPABASE_ANON_KEY || '').trim();

if (!url || !anonKey) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY. Set both environment variables before building.');
}
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) {
  throw new Error('SUPABASE_URL must be your Supabase project URL, e.g. https://project-ref.supabase.co');
}

const output = '/* Generated at build time. Contains only the public Supabase anon/publishable key. */\n' +
  'window.SUPABASE_CONFIG = ' + JSON.stringify({ url, anonKey }) + ';\n';

await writeFile(resolve(process.cwd(), 'supabase-config.js'), output, { encoding: 'utf8', mode: 0o644 });
console.log('Generated supabase-config.js');
