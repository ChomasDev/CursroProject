export class AndoError extends Error {
  notified = false;

  constructor(
    message: string,
    readonly status = 500,
  ) {
    super(message);
    this.name = "AndoError";
  }
}
