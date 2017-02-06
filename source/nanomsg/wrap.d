/**
 This module implements a D convenience API for nanomsg
 */

module nanomsg.wrap;

public import nanomsg.bindings;
public import std.typecons: Yes, No;

enum NanoProtocol {
    request,
    response,
    subscribe,
    publish,
    pull,
    push,
    pair,
    surveyor,
    respondent,
    bus,
}

enum NanoOption {
    lingerMs, /// How long to try and send pending messages after nn_close. -1 means infinite
    sendBufferSize, // Size of the send buffer in bytes
    receiveBufferSize, // Size of the receive buffer in bytes
    receiveMaxSize, /// Maximum message size that can be received, in bytes
    sendTimeoutMs, /// How long in milliseconds it takes for send to timeout
    receiveTimeoutMs, /// How long in milliseconds it takes for receive to timeout
    reconnectIntervalMs, /// How long to wait to re-establish connection
    reconnectIntervalMax, /// Maximum reconnect interval
    sendPriority, /// Outbound priority for endpoints added to socket
    receivePriority, /// Inbout priority for endpoints added to socket
    ipv4Only, /// Self-explanatory
    socketName, /// Socket name for error reporting and statistics
    timeToLive, /// Number of hops before message is dropped
    subscribeTopic, /// Subscription topic
    tcpNoDelay, /// Disables Nagle's algorithm
    surveyorDeadlineMs, /// How long to wait for responses in milliseconds
}

struct ConnectTo {
    string uri;
}

struct BindTo {
    string uri;
}

struct NanoSocket {

    import std.traits: isArray;
    import std.typecons: Flag;


    @disable this(this);

    enum INVALID_FD = -1;

    this(NanoProtocol protocol, int domain = AF_SP) {

        int protocolToInt(NanoProtocol protocol) {
            final switch(protocol) with(NanoProtocol) {
                case request:
                    return NN_REQ;
                case response:
                    return NN_REP;
                case publish:
                    return NN_PUB;
                case subscribe:
                    return NN_SUB;
                case pull:
                    return NN_PULL;
                case push:
                    return NN_PUSH;
                case pair:
                    return NN_PAIR;
                case surveyor:
                    return NN_SURVEYOR;
                case respondent:
                    return NN_RESPONDENT;
                case bus:
                    return NN_BUS;
            }
        }

        _nanoSock = nn_socket(domain, protocolToInt(protocol));
        enforceNanoMsgRet(_nanoSock);
    }

    this(in NanoProtocol protocol, in BindTo bindTo, int domain = AF_SP) {
        import std.string: replace;

        this(protocol, domain);

        // this is so it's easy to specify the same string
        // for both ends of the socket
        bind(bindTo.uri.replace("localhost", "*"));
    }

    this(in NanoProtocol protocol, in ConnectTo connectTo, int domain = AF_SP) {

        this(protocol, domain);
        connect(connectTo.uri);

        version(Windows) {
            // on Windows sometimes the socket tries to send before the TCP handshake
            import core.thread;
            Thread.sleep(100.msecs);
        }
    }

    ~this() {
        if(_nanoSock != INVALID_FD) {
            _nanoSock.nn_close;
        }
    }

    void setOption(T)(NanoOption option, T val) {
        const optionC = toNanoOptionC(option);
        setOption(optionC.level, optionC.option, val);
    }

    ubyte[] receive(int BUF_SIZE = 1024)(Flag!"blocking" blocking = Yes.blocking) {
        // kaleidic.nanomsg.wrap.receive made the tests fail
        import core.stdc.errno;
        ubyte[BUF_SIZE] buf;
        const flags = blocking ? 0 : NN_DONTWAIT;
        auto numBytes = nn_recv(_nanoSock, buf.ptr, buf.length, flags);
        if(blocking) enforceNanoMsgRet(numBytes);

        if(numBytes < 0) numBytes = 0;
        return buf[0 .. numBytes].dup;
    }

    int send(T)(T[] data, Flag!"blocking" blocking = Yes.blocking) {
        int flags = blocking ? 0 : NN_DONTWAIT;
        return nn_send(_nanoSock, data.ptr, data.length, flags);
    }

    void connect(in string uri) {
        import std.string: toStringz;
        enforceNanoMsgRet(nn_connect(_nanoSock, uri.toStringz));
    }

    void bind(in string uri) {
        import std.string: toStringz;
        enforceNanoMsgRet(nn_bind(_nanoSock, uri.toStringz));
    }

private:

    int _nanoSock = INVALID_FD;

    void enforceNanoMsgRet(E)(lazy E expr, string file = __FILE__, size_t line = __LINE__) {
        import core.stdc.errno;
        import core.stdc.string;
        import std.exception: enforce;
        import std.conv: text;
        const value = expr();
        if(value < 0)
            throw new Exception(text("nanomsg expression failed with value ", value,
                                     " errno ", errno, ", error: ", strerror(errno)),
                                file,
                                line);
    }

    // the int level and option values needed by the nanomsg C API
    static struct NanoOptionC {
        int level;
        int option;
    }

    NanoOptionC toNanoOptionC(NanoOption option) {
        final switch(option) with(NanoOption) {
            case lingerMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_LINGER);

            case sendBufferSize:
                return NanoOptionC(NN_SOL_SOCKET, NN_SNDBUF);

            case receiveBufferSize:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVBUF);

            case receiveMaxSize:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVMAXSIZE);

            case sendTimeoutMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_SNDTIMEO);

            case receiveTimeoutMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVTIMEO);

            case reconnectIntervalMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_RECONNECT_IVL);

            case reconnectIntervalMax:
                return NanoOptionC(NN_SOL_SOCKET, NN_RECONNECT_IVL_MAX);

            case sendPriority:
                return NanoOptionC(NN_SOL_SOCKET, NN_SNDPRIO);

            case receivePriority:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVPRIO);

            case ipv4Only:
                return NanoOptionC(NN_SOL_SOCKET, NN_IPV4ONLY);

            case socketName:
                return NanoOptionC(NN_SOL_SOCKET, NN_SOCKET_NAME);

            case timeToLive:
                return NanoOptionC(NN_SOL_SOCKET, NN_TTL);

            case subscribeTopic:
                return NanoOptionC(NN_SUB, NN_SUB_SUBSCRIBE);

            case tcpNoDelay:
                return NanoOptionC(NN_TCP, NN_TCP_NODELAY);

            case surveyorDeadlineMs:
                return NanoOptionC(NN_SURVEYOR, NN_SURVEYOR_DEADLINE);
        }
    }

    void setOption(T)(int level, int option, ref T val) if(isArray!T) {
        enforceNanoMsgRet(nn_setsockopt(_nanoSock, level, option, val.ptr, val.length));
    }

    void setOption(T)(int level, int option, T val) if(!isArray!T) {
        enforceNanoMsgRet(nn_setsockopt(_nanoSock, level, option, &val, val.sizeof));
    }
}
