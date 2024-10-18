using HTTP, JSON3

const SERVER = Ref{HTTP.Servers.Server}()
const ROUTER = HTTP.Router()

find_square(n) = n*n
function square(req)
    data = JSON3.read(req.body, Dict)
    n = data["number"]
    return HTTP.Response(200, JSON3.write(Dict("number" => n, "square" => find_square(n))))
end

HTTP.register!(ROUTER, "POST", "/api/square", square)

function live(req)
    return HTTP.Response(200, JSON3.write("OK"))
end

HTTP.register!(ROUTER, "GET", "/api/live", live)

function run()
    SERVER[] = HTTP.serve(ROUTER, "0.0.0.0", 8000)
end

run()