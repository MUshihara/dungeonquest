return {
    Initial="initialRoom", Final="bossRoom",
    Rooms={
        room1={Kind="Normal"},room2={Kind="Normal"},room3={Kind="Normal"},
        room4={
            Kind="Boss",
            Boss="Sanada Yukimura",
            MultiLevel=true,
            BossLevel="Upper",
            Navigation="PathfindToTargetFloor",
        },
        room5={Kind="Normal"},room6={Kind="Normal"},
        room7={Kind="Boss",Boss="Ancient Golem Guardian"},room8={Kind="Normal"},room9={Kind="Normal"},
        bossRoom={Kind="FinalBoss",Boss="Miyamoto Musashi",RoomIndex=999},
    },
}
