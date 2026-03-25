function before() {
  console.log("apple");
  console.log("orange");
}

function main() {
  before();
  console.log("main");
  after();
}

function after() {
  console.log("banana");
  console.log("grape");
}
