import Foundation
import Alamofire

//: An error that occurs during events, before an HTTP request is made.
public enum EventError: Error {
    //: An error that occurs when a Zulip `narrow` is invalid.
    case invalidEventTypes

    //: An error that occurs when a Zulip `narrow` is invalid.
    case invalidFetchEventTypes

    //: An error that occurs when a Zulip `narrow` is invalid.
    case invalidNarrow
}

/*:
    A client for interacting with Zulip's event functionality.
 */
public class Events {
    private var config: Config

    /*:
        Initializes an Events client.

         - Parameters:
            - config: The `Config` to use.
     */
    public init(config: Config) {
        self.config = config
    }

    /*:
        Registers an event queue.

         - Parameters:
            - applyMarkdown: Whether event content should be rendered as
              Markdown to HTML.
            - clientGravatar: Whether Gravatars should not be sent if a user
              does not have an avatar. (`true` means that `avatar_url` will be
              `nil` if the user does not have an avatar; `false` means that an
              `avatar_url` will be a Gravatar).
            - eventTypes: The types of events to receive, or an empty array
              for all events.
               - Example: `["messages"]` for new messages
               - Example: `["subscriptions"]` for changes in the current user's
                 subscriptions
               - Example: `["realm_user"]` for changes in the users in the
                 current realm
               - Example: `["pointer"]` for changes in the current user's
                 pointer
               - Example: `["subscriptions", "pointer"]` for a combination of
                 multiple events
               - Example: `[]` for all events
            - allPublicStreams: Whether events should be received from all
              public streams.
            - includeSubscribers: Whether events should be received for the
              subscribers of each stream.
            - fetchEventTypes: The same as `eventTypes`, but used to fetch
              initial data. If `fetchEventTypes` is not set, `eventTypes` is
              used, and if neither are set, then no events are used.
            - narrow: A Zulip narrow to search for messages in. `narrow`
              should be an array of arrays consisting of filters.
               - Example: `[["stream", "test here"]]`
               - Example: `[
                     ["stream", "zulip-swift"],
                     ["sender", "theskunkmb@gmail.com"]
                 ]`
            - callback: A callback, which will be passed a dictionary
              containing `queue_id`, the ID of the new queue and
              `last_event_id`, the initial event ID to receive an event with,
              or an error if there is one.
     */
    public func register(
        applyMarkdown: Bool = false,
        clientGravatar: Bool = false,
        eventTypes: [String] = [],
        allPublicStreams: Bool = false,
        includeSubscribers: Bool = false,
        fetchEventTypes: [String] = [],
        narrow: [[String]] = [[]],
        callback: @escaping ([String: Any]?, Error?) -> Void
    ) {
        guard
            let eventTypesData = try? JSONSerialization.data(
                withJSONObject: eventTypes
            ),
            let eventTypesString = String(
                data: eventTypesData,
                encoding: String.Encoding.utf8
            )
        else {
            callback(nil, EventError.invalidEventTypes)
            return
        }

        guard
            let fetchEventTypesData = try? JSONSerialization.data(
                withJSONObject: fetchEventTypes
            ),
            let fetchEventTypesString = String(
                data: fetchEventTypesData,
                encoding: String.Encoding.utf8
            )
        else {
            callback(nil, EventError.invalidFetchEventTypes)
            return
        }

        guard
            let narrowData = try? JSONSerialization.data(
                withJSONObject: narrow
            ),
            let narrowString = String(
                data: narrowData,
                encoding: String.Encoding.utf8
            )
        else {
            callback(nil, EventError.invalidNarrow)
            return
        }

        let params = [
            "apply_markdown": applyMarkdown ? "true" : "false",
            "client_gravatar": clientGravatar ? "true" : "false",
            "event_types": eventTypesString,
            "all_public_streams": allPublicStreams ? "true" : "false",
            "include_subscribers": includeSubscribers ? "true" : "false",
            "fetch_event_types": fetchEventTypesString,
            "narrow": narrowString,
        ]

        makePostRequest(
            url: self.config.apiURL + "/register",
            params: params,
            username: config.emailAddress,
            password: config.apiKey,
            callback: { (response) in
                if let errorMessage = getChildFromJSONResponse(
                    response: response,
                    childKey: "msg"
                ) as? String, errorMessage != "" {
                    callback(
                        nil,
                        ZulipError.error(message: errorMessage)
                    )
                    return
                }

                guard
                    var queue = getDictionaryFromJSONResponse(
                        response: response
                    )
                else {
                    callback(
                        nil,
                        getZulipErrorFromResponse(response: response)
                    )
                    return
                }

                // These keys are unrelated to the actual queue.
                queue.removeValue(forKey: "msg")
                queue.removeValue(forKey: "result")

                callback(queue, nil)
            }
        )
    }

    /*:
        Gets events from a queue.

         - Parameters:
            - queueID: The ID of the queue to get events from.
            - lastEventID: The last event ID to acknowledge. Events after the
              event with the `lastEventID` ID will be sent. `-1` can be used to
              receive all events.
            - dontBlock: Whether the response should be nonblocking. If
              `false`, the response will be sent after a new event is available
              or after a few minutes as a heartbeat.
            - callback: A callback, which will be passed a list of events, or
              an error, if there is one.
     */
    public func get(
        queueID: String,
        lastEventID: Int,
        dontBlock: Bool = false,
        callback: @escaping ([[String: Any]]?, Error?) -> Void
    ) {
        let params = [
            "queue_id": queueID,
            "last_event_id": String(lastEventID),
            "dont_block": dontBlock ? "true" : "false"
        ]

        makeGetRequest(
            url: self.config.apiURL + "/events",
            params: params,
            username: config.emailAddress,
            password: config.apiKey,
            callback: { (response) in
                guard
                    let events = getChildFromJSONResponse(
                        response: response,
                        childKey: "events"
                    ) as? [[String: Any]]
                else {
                    callback(
                        nil,
                        getZulipErrorFromResponse(response: response)
                    )
                    return
                }

                callback(events, nil)
            }
        )
    }

    /*:
        Deletes a queue.

         - Parameters:
            - queueID: The ID of the queue to delete.
            - callback: A callback, which will be passed an error if there is
              one.
     */
    public func deleteQueue(
        queueID: String,
        callback: @escaping (Error?) -> Void
    ) {
        let params = [
            "queue_id": queueID,
        ]

        makeDeleteRequest(
            url: self.config.apiURL + "/events",
            params: params,
            username: config.emailAddress,
            password: config.apiKey,
            callback: { (response) in
                if let errorMessage = getChildFromJSONResponse(
                    response: response,
                    childKey: "msg"
                ) as? String, errorMessage != "" {
                    callback(
                        ZulipError.error(message: errorMessage)
                    )
                    return
                }

                callback(nil)
            }
        )
    }
}
