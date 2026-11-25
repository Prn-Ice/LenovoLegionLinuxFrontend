# Comment template: Ester's browser sessions

Ester's dashboard sends requests to an API. `BrowserSessions` helps the API
check those requests and read or set the sign-in cookie. Each pair below
documents the **same code** before and after a comment edit. In your own
project, read the function and its caller first; borrow the pattern, not
Ester's terminology.

### 1. At the class: what is this for?

**Before (vague):**

```dart
/// Cookie and request rules for the dashboard's browser sessions.
/// Applies browser rules before a route changes data.
class BrowserSessions {
```

The first line is a useful summary. The second leaves the reader to guess:
who calls this class, which method do they call, and what does it check?

**After (keep the summary; name the caller, method, and checks):**

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

### 2. At the helper: what question does it answer?

**Before (explains a missing header, not the result):**

```dart
/// Omitting the CSRF header cannot opt a browser out of these rules.
bool appliesTo(Request request) =>
```

If the header is missing but the session cookie is present, would this return
`true` or `false`? The comment should let a caller answer without tracing the
whole request.

**After (name the inputs and both outcomes):**

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

**Before (names only the error case):**

```dart
/// Returns a rejection before browser mutations reach authentication/routes.
Response? rejectUnsafeRequest(Request request) {
```

The `?` says the result can be `null`, but not what the API does with it.
Read the caller before documenting that result.

**After (say what stops and what continues):**

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

Here `appliesTo == false` skips this check. The API still checks authentication
on protected routes. Describing `null` as “access granted” would be wrong.

### 4. Beside a branch: does the code here support the comment?

**Before (claims more than the branch shows):**

```dart
// Let the router handle this request so the user can sign out safely.
if (rejection != null) return rejection;
```

**After (remove the comment):**

```dart
if (rejection != null) return rejection;
```

The branch returns an error. It doesn't call a router or sign anyone out.
The method comment already explains the result, so no replacement is needed.

### 5. After a rename or fix: drop defensive sidechatter

**Before (argues with a deleted name and cites an unrelated method):**

```dart
/// Sum of loaded [InviteLink.registrations] counters (not a weekly total;
/// refreshing a link resets its server counter).
int get totalRegistrations {
  return links.fold(0, (sum, l) => sum + l.registrations);
}
```

**After (states what this getter returns now):**

```dart
/// Total registrations across the loaded invite links.
int get totalRegistrations {
  return links.fold(0, (sum, l) => sum + l.registrations);
}
```

Say what the code does now in positive terms. Record old names, audit disclaimers,
and fixed bugs in Beads or PR notes, and document another method's reset
behavior on that method or field.

**Use this pattern in older code, too.** Fix unclear comments as you encounter
them. Put a reason beside the decision it explains. If the code below only
builds a loading screen, describe that screen there. Explain routing where
the router actually chooses a page. If a line adds no useful explanation,
leave it out.
