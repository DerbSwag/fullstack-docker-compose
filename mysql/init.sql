USE fullstack;

CREATE TABLE IF NOT EXISTS users (
  id INT NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
);

INSERT INTO users (name, email) VALUES
('Nattawat Rueangkhum', 'nattawat@example.com'),
('Anan Somchai', 'anan@example.com'),
('Benjamas Suksri', 'benjamas@example.com'),
('Chaiwat Meesuk', 'chaiwat@example.com'),
('Daranee Khamdee', 'daranee@example.com'),
('Ekkachai Saelim', 'ekkachai@example.com'),
('Fahlada Wongsa', 'fahlada@example.com'),
('Kittipong Boonmee', 'kittipong@example.com'),
('Manatsawee Jaidee', 'manatsawee@example.com'),
('Pongsakorn Thongdee', 'pongsakorn@example.com');
