module.exports = {
  default: {
    require: [
      "features/support/**/*.js",
      "features/step_definitions/**/*.js"
    ],
    paths: [
      "features/**/*.feature"
    ],
    publishQuiet: true
  }
}
