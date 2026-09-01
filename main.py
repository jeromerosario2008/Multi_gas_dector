from fastapi import FastAPI
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Gas Sentinel API")

# Enable CORS so your Flutter frontend can fetch data without issues
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Current sensor state
sensor_data = {
    "lpg": 120.0,
    "co": 18.0,
    "smoke": 85.0,
    "exhaust_fan": False,
    "status": "SAFE"
}

class GasReading(BaseModel):
    lpg: float
    co: float
    smoke: float

@app.get("/")
def home():
    return {"message": "Gas Sentinel Backend Active"}

@app.get("/api/sensor-data")
def get_sensor_data():
    return sensor_data

@app.post("/api/sensor-data")
def update_sensor_data(data: GasReading):
    global sensor_data
    is_danger = data.lpg > 250 or data.co > 50 or data.smoke > 150
    sensor_data.update({
        "lpg": data.lpg,
        "co": data.co,
        "smoke": data.smoke,
        "status": "DANGER" if is_danger else "SAFE"
    })
    return {"status": "updated", "data": sensor_data}