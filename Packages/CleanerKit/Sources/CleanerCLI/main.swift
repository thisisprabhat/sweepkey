import ArgumentParser

struct Cleaner: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleaner",
        abstract: "Clean regenerable developer artifacts and collect secrets into a vault.",
        version: "0.1.0"
    )
}

Cleaner.main()
