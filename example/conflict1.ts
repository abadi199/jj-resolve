function before() {
  console.log("APPLE");
  console.log("ORANGE");
}

function main() {
  before();
  console.log("MAIN");
  after();
}

function after() {
  console.log("BANANA");
  console.log("GRAPE");
}
