// AX-only tools and idle daemons do not need the native image library.
let processor;
export function imageProcessor() {
  return processor ??= import('sharp').then(({ default: sharp }) => {
    if (process.platform === 'darwin') sharp.concurrency(Math.min(sharp.concurrency(), 2));
    return sharp;
  });
}
