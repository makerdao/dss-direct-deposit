{ url
  , dappPkgs ? (
    import (fetchTarball "https://github.com/makerdao/makerpkgs/tarball/master") {}
  ).dappPkgsVersions.master-20220524
}: with dappPkgs;

mkShell {
  DAPP_SOLC = solc-static-versions.solc_0_8_14 + "/bin/solc-0.8.14";
  # No optimizations
  SOLC_FLAGS = "";
  buildInputs = [
    dapp
  ];

  shellHook = ''
    export NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    unset SSL_CERT_FILE

    export ETH_RPC_URL="''${ETH_RPC_URL:-${url}}"
  '';
}
