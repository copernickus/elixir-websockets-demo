% Add misultin as dependency
Erlang.code.add_path $"deps/misultin/ebin"

% Add ex_bridge as dependency and load it
Code.unshift_path "deps/ex_bridge/lib"
Code.require "ex_bridge/misultin"

module Chat
  object Backend
    module Mixin
      def start
        { 'ok, _pid } = GenServer.start_link({ 'local, 'chat_backend }, self.new, [])
      end

      def new_user
        GenServer.call 'chat_backend, 'new_user
      end

      def send_message(message)
        GenServer.cast 'chat_backend, { 'message, Process.self, message }
      end

      def set_nick(nick)
        GenServer.cast 'chat_backend, { 'set_nick, Process.self, nick }
      end
    end

    def constructor()
      { 'users: {:} }
    end

    def broadcast(message)
      @users.each do (pid, _nick)
        pid <- { 'chat_server, { 'message, message } }
      end
    end

    protected

    def init()
      Process.flag 'trap_exit, true
      { 'ok, self }
    end

    def handle_call('new_user, { pid, _ref })
      Process.link(pid)
      updated = self.set_ivar 'users, @users.set(pid, "Unknown")
      { 'reply, 'ok, updated }
    end

    def handle_call(_request, _from)
      { 'reply, 'undef, self }
    end

    def handle_cast({ 'message, pid, message })
      broadcast "#{@users[pid]}: #{message}"
      { 'noreply, self }
    end

    def handle_cast({ 'set_nick, pid, nick })
      updated = self.update_ivar 'users, -> (u) u.set(pid, nick)
      { 'noreply, updated }
    end

    def handle_cast(_request)
      { 'noreply, self }
    end

    def handle_info({ 'EXIT, pid, _reason })
      updated = self.update_ivar 'users, _.delete(pid)
      updated.broadcast "#{@users[pid]} left the room."
      { 'noreply, updated }
    end

    def handle_info(_request)
      { 'noreply, self }
    end

    def terminate(_reason)
      'ok
    end

    def code_change(_old, _extra)
      { 'ok, self }
    end
  end

  module Server
    def start
      options = {
        'port: 8080,
        'loop: -> (req) handle_http( ExBridge.request('misultin, req, 'docroot: "assets") ),
        'ws_loop: -> (socket) handle_websocket( ExBridge.websocket('misultin, socket) )
      }

      { 'ok, _pid } = Erlang.misultin.start_link options.to_list
    end

    def handle_websocket(socket)
      Chat::Backend.new_user
      socket_loop(socket)
    end

    def socket_loop(socket)
      receive
      match { 'browser, data }
        % kind <- message
        string = String.new(data)

        case string.split(~r{ <- }, 2)
        match ["msg", msg]
          Chat::Backend.send_message(msg)
        match ["nick", nick]
          Chat::Backend.set_nick(nick)
        else
          socket.send "status <- received #{string}"
        end

        socket_loop(socket)
      match { 'chat_server, { 'message, message } }
        string = String.new(message)
        socket.send "output <- #{string}"
        socket_loop(socket)
      match other
        IO.puts "SOCKET UNKNOWN #{other}"
        socket_loop(socket)
      after 10000
        socket.send "tick"
        socket_loop(socket)
      end
    end

    def handle_http(request)
      status = case { request.request_method, request.path }
      match { 'GET, "/chat.html" }
        body = File.read "assets/chat.html"
        request.respond 200, { "Content-Type": "text/html" }, body
      match { 'GET, path }
        request.serve_file path[1,-1]
      else
        request.respond 404, {}, "Not Found"
      end
       
      IO.puts "HTTP #{request.request_method} #{status} #{request.path}" 
    end
  end
end

Chat::Backend.start
Chat::Server.start

IO.puts "Started on http://localhost:8080/"