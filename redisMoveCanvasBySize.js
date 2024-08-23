/*
 * move 3d canvas chunks from one redis instance to another
 */

const redis = require('redis');
const createClient = redis.createClient;
const commandOptions = redis.commandOptions;

const urlt = "redis://localhost:6379";
const redist = createClient({ url: urlt });

const OLD_CANVAS_SIZE = 16384;
const NEW_CANVAS_SIZE = 32768;
const TILE_SIZE = 256;
const CANVAS_ID = 1;

const OLD_CHUNKS_XY = OLD_CANVAS_SIZE / TILE_SIZE;
const NEW_CHUNKS_XY = NEW_CANVAS_SIZE / TILE_SIZE;

async function move() {
  await redist.connect();
  console.log('redis connected');
  console.log(`Old canvas: ${OLD_CANVAS_SIZE} / ${OLD_CHUNKS_XY}`);
  console.log(`New canvas: ${NEW_CANVAS_SIZE} / ${NEW_CHUNKS_XY}`);
  const diff = (NEW_CHUNKS_XY - OLD_CHUNKS_XY) / 2;
  console.log(`Moving canvas chunks by ${diff}`);

  console.log('Moving chunks...');
  for (let x = OLD_CHUNKS_XY - 1; x >= 0; x--) {
    for (let y = OLD_CHUNKS_XY - 1; y >= 0; y--) {
      const oldKey = `ch:${CANVAS_ID}:${x}:${y}`;
      const newKey = `ch:${CANVAS_ID}:${x + diff}:${y + diff}`;
      const chunk = await redist.get(
        commandOptions({ returnBuffers: true }),
        oldKey,
      );
      if (chunk) {
        const ret = await redist.set(newKey, Buffer.from(chunk.buffer));
        await redist.del(oldKey);
        console.log(`${oldKey} -> ${newKey}`);
      } else {
        console.log(`no chunks ${oldKey}`);
      }
    }
  }
  console.log("done");
}

move();
