{ buildLocalRustBin }:
buildLocalRustBin {
  pname = "beans-daemon";
  version = "0.1.0";
  bins = [
    "beansd"
    "beansctl"
  ];
  meta.description = "Background daemon (beansd) and control CLI (beansctl) for the beans issue tracker";
}
