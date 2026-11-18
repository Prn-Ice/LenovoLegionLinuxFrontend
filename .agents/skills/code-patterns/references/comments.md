# Comment template: Ester's browser sessions

Start with the job. Name the main method, who calls it, and which helper makes
the decision. Give each helper a comment a reader can understand on its own.
The excerpts below show three places to tell different parts of the same story.

### 1. At the class: what is this for?

```dart
/// Cookie and request rules for the dashboard's browser sessions.
///
/// The API calls [rejectUnsafeRequest] before it handles a request.
/// [rejectUnsafeRequest] uses [appliesTo] to recognize browser requests.
/// Before allowing a change such as signing out, it checks that `Origin`
/// matches an allowed dashboard address and `X-Ester-CSRF` is `1`.
/// If the request specifies a content type, it must be JSON.
///
/// At sign-in, the API uses [cookie] to tell the browser to save the session
/// token. On later requests, [token] reads it back so the API can check the
/// session. At sign-out, [expiredCookie] tells the browser to remove it.
class BrowserSessions {
```

“Applies browser rules” leaves the reader guessing. The overview names the
two checks and uses signing out as a familiar example. It also names the cookie
methods in the order a signed-in person encounters them.

### 2. At the helper: what question does it answer?

```dart
/// Treats a request as a browser request if it includes `Origin`,
/// `X-Ester-CSRF`, or the session cookie. Otherwise returns false.
bool appliesTo(Request request) =>
    request.headers.containsKey('origin') ||
    request.headers.containsKey('x-ester-csrf') ||
    (request.headers['cookie'] ?? '')
        .split(';')
        .any((part) => part.trim().startsWith('$cookieName='));
```

Stop there. This method classifies a request. It doesn't reject it, sign anyone
in, or decide whether someone may open a protected page.

### 3. At the main method and its caller: what happens next?

```dart
/// Returns an error to stop the request, or `null` to let it continue.
/// Skips non-browser requests and GET, HEAD, and OPTIONS.
Response? rejectUnsafeRequest(Request request) {
  if (!appliesTo(request) ||
      const {
        HttpMethod.get,
        HttpMethod.head,
        HttpMethod.options,
      }.contains(request.method)) {
    return null;
  }
  // … remaining checks omitted from this excerpt …
```

The API middleware uses that result here:

```dart
final rejection = browser.rejectUnsafeRequest(context.request);
if (rejection != null) return rejection;
```

Now the reader can answer “Does `false` reject the request?” by following two
short branches: `false` makes this check return `null`; the middleware returns
early only for an error. Otherwise it continues handling the request.

**Use this pattern in older code, too.** Fix unclear comments as you encounter
them. Put a reason beside the decision it explains. If the code below only
builds a loading screen, describe that screen there. Explain routing where
the router actually chooses a page. If a line adds no useful explanation,
leave it out.
