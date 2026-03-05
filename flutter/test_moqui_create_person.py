import requests

s = requests.Session()
r_login = s.post("http://localhost:8080/rest/login", json={"username": "john.doe", "password": "moqui"})
print("Login:", r_login.json())

csrf = r_login.headers.get("X-CSRF-Token")
headers = {"X-CSRF-Token": csrf, "Accept": "application/json"}

print("Posting to createPerson...")
r = s.post("http://localhost:8080/fapps/marble/Party/FindParty/createPerson", 
           data={"firstName": "Test", "lastName": "Person", "roleTypeId": "Customer"},
           headers=headers, allow_redirects=False)
print("Status:", r.status_code)
print("Headers:", r.headers)
try:
    print("Response JS:", r.json())
except:
    print("Response text:", r.text[:200])

