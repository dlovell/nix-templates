{
  description = "personal flake templates";
  outputs = { self }: {
    templates = {
      default = self.templates.nix-maturin;
      nix-maturin = {
        path = ./nix-maturin;
        description = "maturin/pyo3 template via crane";
      };
    };
  };
}
