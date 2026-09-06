export class ProductError extends Error {
  constructor(code, message, status = 400) {
    super(message); this.name = 'ProductError'; this.code = code; this.status = status;
  }
}
export function requireValue(condition, code, message, status = 400) {
  if (!condition) throw new ProductError(code, message, status);
}
export class SerialQueue {
  #tail = Promise.resolve();
  run(operation) {
    const result = this.#tail.then(operation, operation);
    this.#tail = result.catch(() => {});
    return result;
  }
}
