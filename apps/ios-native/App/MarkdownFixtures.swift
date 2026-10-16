import Foundation

#if DEBUG
enum MarkdownFixtures {
    static let document = """
    ## Keep your place on reconnect

    The open conversation keeps its **thread ID**. After reconnecting, the client replaces stale content with a fresh snapshot.

    1. Restore the saved environment.
    2. Subscribe to the open conversation.
       - Keep the local draft.
       - Replace the server projection.
    3. Resume incoming messages.

    > Reconnecting does not resend your last message. A timed-out send may already have reached the server.

    ### Connection states

    | State | Draft | Server data |
    | :--- | :---: | ---: |
    | Offline | Saved | Last snapshot |
    | Connecting | Saved | Refreshing |
    | Connected | Saved | Live |

    ```swift
    if phase == .active {
        store.resume()
    }
    if phase == .background {
        store.disconnect()
    }
    ```

    See the [T3 protocol](https://github.com/pingdotgg/t3code/tree/main/packages/contracts) for the wire types.
    """
}
#endif
