import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 6000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#1A5CC8" }
        Column {
            anchors.centerIn: parent; spacing: 16
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "Benvenuto in AuraOS"; font.pixelSize: 32
                   font.bold: false; font.weight: Font.Light; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "Linux veloce, elegante e sicuro."
                   font.pixelSize: 18; color: "#B8D8FF" }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#1248A8" }
        Column {
            anchors.centerIn: parent; spacing: 16
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "App Store integrato"; font.pixelSize: 32
                   font.weight: Font.Light; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "Migliaia di applicazioni disponibili\ntramite GNOME Software e Flatpak."
                   font.pixelSize: 18; color: "#B8D8FF"; horizontalAlignment: Text.AlignHCenter }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#0D3A8A" }
        Column {
            anchors.centerIn: parent; spacing: 16
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "Navigazione protetta"; font.pixelSize: 32
                   font.weight: Font.Light; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "AdGuard Home blocca pubblicità\ne tracker a livello di rete."
                   font.pixelSize: 18; color: "#B8D8FF"; horizontalAlignment: Text.AlignHCenter }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#1A5CC8" }
        Column {
            anchors.centerIn: parent; spacing: 16
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "Quasi pronto!"; font.pixelSize: 32
                   font.weight: Font.Light; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: "L'installazione sta per completarsi.\nRiavvia quando richiesto."
                   font.pixelSize: 18; color: "#B8D8FF"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
