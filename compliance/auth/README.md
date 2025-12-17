
# 基础概念

- 身份认证（Authentication）：确定“你是谁”，比如登录、校验密码、短信验证码等。
- 授权（Authorization）：确定“你能做什么”，比如有哪些角色、能访问哪些 API。
- SSO（Single Sign-On，单点登录）：用户在一个地方登录后，可以无感访问多个系统。
- IdP（Identity Provider）：身份提供方，负责登录、签发凭证（如 OIDC Provider、SAML IdP）。
- 资源服务器（Resource Server）：提供 API 或资源的服务，校验 Access Token

# Session Token

最经典的“用户名 + 密码 + Session”的网站登录方式。

```plantuml
@startuml
actor User
participant Browser
participant "App Server" as App
database "User DB" as DB

User -> Browser: Open /login
Browser -> App: GET /login
App --> Browser: 200 Login page

User -> Browser: Submit username & password
Browser -> App: POST /login (credentials)
App -> DB: Verify username & password
DB --> App: OK

App -> App: Create session (session_id)
App --> Browser: 302 Redirect to /
note right of App: Set-Cookie: session_id=...

Browser -> App: GET /
App -> App: Find session by session_id
App --> Browser: 200 Home page (logged in)

@enduml
```

# Jwt Token

用户允许一个应用（Client）在一定范围内，代表自己去访问另一服务（Resource Server）的资源。

```plantuml
@startuml
actor User
participant Browser
participant "Client App" as Client
participant "Authorization Server" as AS
participant "Resource Server" as RS

User -> Browser: Click "Connect with Provider"
Browser -> Client: GET /connect
Client --> Browser: 302 Redirect to AS /authorize

Browser -> AS: GET /authorize\n?client_id&redirect_uri&scope&state&response_type=code
AS -> User: Show login & consent page
User -> AS: Enter credentials and consent
AS --> Browser: 302 Redirect to redirect_uri\n?code=...&state=...

Browser -> Client: GET /callback?code=...
Client -> AS: POST /token\n(grant_type=authorization_code, code,...)
AS --> Client: 200 { access_token, refresh_token? }

Client -> RS: GET /api/resource\nAuthorization: Bearer access_token
RS --> Client: 200 { data }
Client --> Browser: Render page with data

@enduml
```


OIDC 一般指 OpenID Connect。

