# EZSops

EZSops is a tool for encrypting and decrypting files using `sops` with `KMS` keys.
It helps avoid many of the pitfalls of using `sops` directly, and introduces much needed quality of life features:

- Keeps a record of KMS keys used in the past for easy re-use
- Detects if the file was not correctly encrypted
- Automatically sets the output file name

## Installation

To install EZSops, you can use `bpkg`, a bash package manager. If you don't have `bpkg` installed, you can find instructions at https://bpkg.sh/.

Once `bpkg` is installed, run the following command:

```sh
bpkg install ezsops
```

## Usage

EZSops provides two commands: `encrypt` and `decrypt`. Both commands take a single argument, the file to encrypt or decrypt.

```sh
ezsops encrypt secret.yml
ezsops decrypt sops.secret.yml
```
