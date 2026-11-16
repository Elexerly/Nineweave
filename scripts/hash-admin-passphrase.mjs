#!/usr/bin/env node
import { randomBytes, scrypt } from "node:crypto";

const passphrase = process.env.NINEWEAVE_ADMIN_PASSPHRASE;
if (!passphrase?.trim()) {
  console.error("NINEWEAVE_ADMIN_PASSPHRASE must be set and nonempty");
  process.exitCode = 1;
} else {
  const salt = randomBytes(16);
  scrypt(passphrase, salt, 32, { N: 16384, r: 8, p: 1 }, (error, hash) => {
    if (error) {
      console.error("Could not hash admin passphrase");
      process.exitCode = 1;
      return;
    }
    console.log(`scrypt$${salt.toString("hex")}$${hash.toString("hex")}`);
  });
}
