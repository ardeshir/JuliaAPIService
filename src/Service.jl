using HTTP, JSON3

const SERVER = Ref{HTTP.Servers.Server}()
const SERVER_ROUTER = HTTP.Router()

find_square(n) = n*n
function square(req)
    data = JSON3.read(req.body, Dict)
    n = data["number"]
    return HTTP.Response(200, JSON3.write(Dict("number" => n, "square" => find_square(n))))
end

HTTP.register!(SERVER_ROUTER, "POST", "/api/square", square)

function live(req)
    return HTTP.Response(200, JSON3.write("OK"))
end

HTTP.register!(SERVER_ROUTER, "GET", "/api/live", live)

function run()
    SERVER[] = HTTP.serve(SERVER_ROUTER, "0.0.0.0", 8000)
end

run()