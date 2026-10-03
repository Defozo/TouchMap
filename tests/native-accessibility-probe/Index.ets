@Entry
@Component
struct Index {
  build() {
    Column({ space: 24 }) {
      Text('TouchMap hover test probe').fontSize(26)
      Text('This test service enables native touch-guide dispatch for instrumentation. It does not read text aloud and is not a screen reader.').fontSize(18)
      Text('Enable the service temporarily in Settings > Accessibility, run the hover test, then disable it.').fontSize(18)
    }.padding(24).width('100%')
  }
}
