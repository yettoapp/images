# images

Images used across the Yetto-verse.

## Directory hierarchy

The layout for this repository is very specific, and follows certain guidelines. Roughly, it looks like this:

```
├── app
│   └── plug
│       └── ruby
│           └── Dockerfile
├── base
│   └── rails
│       ├── Dockerfile
├── bin
│   ├── chrome
│   │   └── Dockerfile
│   ├── op
│   │   └── Dockerfile
│   └── tailscale
│       └── Dockerfile
└── service
    └── postgres
        └── Dockerfile
```

- Use `app` for any applications
- Use `base` for any dependency compilations which the `app`s require
- Place `bin`s installed into `app`s in `bin`
- Place any services in, well, `service`

## Building images

To build any Dockerfile, call:

```
script/build <path>
```

That will build `<path>/Dockerfile`, tagged with `latest`. For example, the following command:

```
script/build service/postgres
```

builds `service/postgres/Dockerfile`, and tags it as `yettoapp/service-postgres:main`.
