// Gluegun still calls the original CommonJS decompress API. Use the maintained
// implementation through its public async API, retaining Promise semantics.
module.exports = async (...args) => {
  const { default: decompress } = await import('@xhmikosr/decompress');
  return decompress(...args);
};
